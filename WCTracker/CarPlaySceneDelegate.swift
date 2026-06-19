import CarPlay
import UIKit

/// Hosts the CarPlay scene. Builds the template hierarchy from the shared stores
/// and refreshes it once a second so the scoreboard clock ticks and score / stat /
/// lineup changes show up. Routed here from the CarPlay scene role in Info.plist.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let interface = CarPlayInterface()
    private var timer: Timer?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        // Render the scoreboard image at the car screen's scale so it stays crisp.
        let scale = interfaceController.carTraitCollection.displayScale
        interface.imageScale = scale > 0 ? scale : 2

        let env = AppEnvironment.shared
        env.startIfNeeded()
        interface.update(env: env)
        interfaceController.setRootTemplate(interface.rootTemplate, animated: false, completion: nil)

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.interface.update(env: AppEnvironment.shared)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        timer?.invalidate()
        timer = nil
        self.interfaceController = nil
    }
}
