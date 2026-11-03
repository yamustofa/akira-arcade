//
//  FakePhoneController.swift
//  Delta
//
//  Akira Arcade, stage 1: a fake phone controller for testing PhoneGameController
//  before the real phone server exists. Delta hides the touch controls while an
//  external controller is connected, so the fake also gets past title screens: it
//  taps Start 2 s and 4 s after a game opens, then presses Right for half a second,
//  every second, so a game character walks without anyone touching the iPad.
//
//  Debug builds only, and off unless the app is launched with
//  `-AkiraFakePhoneController YES` (Delta scheme → Run → Arguments).
//

#if DEBUG

import Foundation
import SwiftUI
import DeltaCore

final class FakePhoneController
{
    static let shared = FakePhoneController()
    
    private var controller: PhoneGameController?
    private var timer: Timer?
    
    private init()
    {
    }
    
    func startIfRequested()
    {
        // Akira Arcade, stage 2 testing: start the phone controller server at launch, so the
        // phone page can be tested without opening a game. Off unless launched with
        // `-AkiraStartPhoneServer YES`; `-AkiraPhoneToken <token>` fixes the token.
        if UserDefaults.standard.bool(forKey: "AkiraStartPhoneServer")
        {
            let token = UserDefaults.standard.string(forKey: "AkiraPhoneToken") ?? "akira-debug"
            PhoneControllerServer.shared.start(token: token)
        }
        
        // `-AkiraShowPhoneControllerView YES` opens the QR screen right after launch, so it can be
        // checked without opening a game and its pause menu.
        if UserDefaults.standard.bool(forKey: "AkiraShowPhoneControllerView")
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else { return }
                while let presented = presenter.presentedViewController
                {
                    presenter = presented
                }
                presenter.present(UIHostingController(rootView: PhoneControllerView()), animated: true)
            }
        }
        
        guard UserDefaults.standard.bool(forKey: "AkiraFakePhoneController"), self.controller == nil else { return }
        
        let controller = PhoneGameController(name: "Fake Phone")
        ExternalGameControllerManager.shared.connect(controller)
        self.controller = controller
        
        // One tick every half second, counted from the moment a game is listening to
        // this controller (it has receivers): Start at ticks 4 and 8, then Right on
        // every other tick. Leaving the game resets the count.
        var tick = 0
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard !controller.receivers.isEmpty else {
                tick = 0
                controller.update(buttonMask: 0)
                return
            }
            
            tick += 1
            
            let mask: UInt32
            switch tick
            {
            case 4, 8: mask = PhoneGameController.Input.start.bit
            case ..<10: mask = 0
            default: mask = tick.isMultiple(of: 2) ? PhoneGameController.Input.right.bit : 0
            }
            
            controller.update(buttonMask: mask)
        }
    }
}

#endif
