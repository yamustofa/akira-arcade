//
//  FakePhoneController.swift
//  Delta
//
//  Akira Arcade, stage 1: a fake phone controller for testing PhoneGameController
//  before the real phone server exists. It presses Right for half a second, every
//  second, so a game character walks without anyone touching the iPad.
//
//  Debug builds only, and off unless the app is launched with
//  `-AkiraFakePhoneController YES` (Delta scheme → Run → Arguments).
//

#if DEBUG

import Foundation
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
        guard UserDefaults.standard.bool(forKey: "AkiraFakePhoneController"), self.controller == nil else { return }
        
        let controller = PhoneGameController(name: "Fake Phone")
        ExternalGameControllerManager.shared.connect(controller)
        self.controller = controller
        
        var isPressed = false
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            isPressed.toggle()
            controller.update(buttonMask: isPressed ? PhoneGameController.Input.right.bit : 0)
        }
    }
}

#endif
