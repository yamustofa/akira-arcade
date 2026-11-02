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
            
            let mask: UInt16
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
