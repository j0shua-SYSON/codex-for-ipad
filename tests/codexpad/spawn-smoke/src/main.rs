use std::io;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

unsafe extern "C" {
    fn prctl(option: i32, ...) -> i32;
    fn getppid() -> i32;
}

fn arm_parent_check(command: &mut Command) {
    let parent = std::process::id() as i32;
    unsafe {
        command.pre_exec(move || {
            if prctl(1, 15_i32, 0_i32, 0_i32, 0_i32) == -1 {
                return Err(io::Error::last_os_error());
            }
            if getppid() != parent {
                return Err(io::Error::other("parent process ID changed"));
            }
            Ok(())
        });
    }
}

fn main() {
    if std::env::args().any(|arg| arg == "--child") {
        println!("stdout-from-child");
        eprintln!("stderr-from-child");
        std::process::exit(7);
    }
    std::thread::spawn(|| {
        let mut command = Command::new("/spawn-smoke");
        command.arg("--child").stdin(Stdio::inherit()).stdout(Stdio::piped()).stderr(Stdio::piped());
        arm_parent_check(&mut command);
        let output = command.spawn().expect("spawn via patched std").wait_with_output().unwrap();
        assert_eq!(output.status.code(), Some(7));
        assert_eq!(output.stdout, b"stdout-from-child\n");
        assert_eq!(output.stderr, b"stderr-from-child\n");
        let mut missing = Command::new("/deliberately-missing-spawn-target");
        arm_parent_check(&mut missing);
        assert_eq!(missing.spawn().unwrap_err().raw_os_error(), Some(2));
    }).join().expect("spawn worker");
    println!("PASS: patched Rust std spawns from a worker thread and preserves exec errors");
}
