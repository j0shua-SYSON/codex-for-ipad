import SwiftUI
import UIKit

@objc(CodexPadHostViewController)
@MainActor
public final class CodexPadHostViewController: UIViewController {
    private let terminalViewController: UIViewController
    private let model = CodexWorkspaceModel()
    private var workspaceController: UIHostingController<CodexPadRootView>?
    private let returnButton = UIButton(type: .system)

    @objc(initWithTerminalViewController:)
    public init(terminalViewController: UIViewController) {
        self.terminalViewController = terminalViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        addChild(terminalViewController)
        terminalViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalViewController.view)
        NSLayoutConstraint.activate([
            terminalViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            terminalViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        terminalViewController.didMove(toParent: self)

        let root = CodexPadRootView(model: model) { [weak self] in
            self?.setTerminalVisible(true)
        }
        let workspaceController = UIHostingController(rootView: root)
        self.workspaceController = workspaceController
        addChild(workspaceController)
        workspaceController.view.translatesAutoresizingMaskIntoConstraints = false
        workspaceController.view.backgroundColor = .clear
        view.addSubview(workspaceController.view)
        NSLayoutConstraint.activate([
            workspaceController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            workspaceController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            workspaceController.view.topAnchor.constraint(equalTo: view.topAnchor),
            workspaceController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        workspaceController.didMove(toParent: self)

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Return to Codex"
        configuration.image = UIImage(systemName: "chevron.backward")
        configuration.imagePadding = 7
        configuration.cornerStyle = .capsule
        returnButton.configuration = configuration
        returnButton.addTarget(self, action: #selector(returnToWorkspace), for: .touchUpInside)
        returnButton.accessibilityIdentifier = "codexpad.return-to-workspace"
        returnButton.translatesAutoresizingMaskIntoConstraints = false
        returnButton.isHidden = true
        view.addSubview(returnButton)
        NSLayoutConstraint.activate([
            returnButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            returnButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            returnButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    public override var prefersStatusBarHidden: Bool { false }

    @objc private func returnToWorkspace() {
        setTerminalVisible(false)
    }

    private func setTerminalVisible(_ visible: Bool) {
        workspaceController?.view.isHidden = visible
        returnButton.isHidden = !visible
        if visible {
            view.bringSubviewToFront(returnButton)
            terminalViewController.view.accessibilityViewIsModal = true
        } else {
            workspaceController?.view.accessibilityViewIsModal = true
        }
        setNeedsStatusBarAppearanceUpdate()
    }
}
