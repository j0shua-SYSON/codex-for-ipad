import SwiftUI
import UIKit

@objc(CodexPadHostViewController)
@MainActor
public final class CodexPadHostViewController: UIViewController {
    private let terminalViewController: UIViewController
    private let model = CodexWorkspaceModel()
    private var workspaceController: UIHostingController<CodexPadRootView>?
    private let returnButton = UIButton(type: .system)
    private var isTerminalVisible = false

    private static let activateTerminalInputSelector = NSSelectorFromString("codexPadActivateInput")
    private static let deactivateTerminalInputSelector = NSSelectorFromString("codexPadDeactivateInput")

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

        setTerminalVisible(false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isTerminalVisible else { return }
        deactivateTerminalInput()
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    public override var prefersStatusBarHidden: Bool { false }

    @objc private func returnToWorkspace() {
        setTerminalVisible(false)
    }

    private func setTerminalVisible(_ visible: Bool) {
        isTerminalVisible = visible
        terminalViewController.view.isHidden = !visible
        terminalViewController.view.isUserInteractionEnabled = visible
        terminalViewController.view.accessibilityElementsHidden = !visible
        workspaceController?.view.isHidden = visible
        workspaceController?.view.isUserInteractionEnabled = !visible
        workspaceController?.view.accessibilityElementsHidden = visible
        returnButton.isHidden = !visible
        if visible {
            view.bringSubviewToFront(returnButton)
            terminalViewController.view.accessibilityViewIsModal = true
            workspaceController?.view.accessibilityViewIsModal = false
            _ = terminalViewController.perform(Self.activateTerminalInputSelector)
        } else {
            deactivateTerminalInput()
            terminalViewController.view.accessibilityViewIsModal = false
            workspaceController?.view.accessibilityViewIsModal = true
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    private func deactivateTerminalInput() {
        _ = terminalViewController.perform(Self.deactivateTerminalInputSelector)
        view.endEditing(true)

        // iSH requests focus while its storyboard is loading. Repeat once after
        // UIKit has made the host window key so that focus cannot be restored
        // behind the native workspace.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTerminalVisible else { return }
            _ = self.terminalViewController.perform(Self.deactivateTerminalInputSelector)
            self.view.endEditing(true)
        }
    }
}
