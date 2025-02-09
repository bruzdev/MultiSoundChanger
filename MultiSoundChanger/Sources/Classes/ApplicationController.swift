//
//  ApplicationController.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 20.04.21.
//  Copyright © 2021 Dmitry Medyuho. All rights reserved.
//

import Foundation
import MediaKeyTap
import SimplyCoreAudio
import UserNotifications


// MARK: - Protocols

protocol ApplicationController: class {
    func start()
}

// MARK: - Implementation

final class ApplicationControllerImp: ApplicationController {
    private lazy var simplyCA: SimplyCoreAudio = SimplyCoreAudio()
    private lazy var audioManager: AudioManager = AudioManagerImpl()
    private lazy var mediaManager: MediaManager = MediaManagerImpl(delegate: self)
    private lazy var statusBarController: StatusBarController = StatusBarControllerImpl(audioManager: audioManager, simplyCoreAudio: simplyCA)
    
    var observers: [NSObjectProtocol] = []

    func start() {
        statusBarController.createMenu()
        mediaManager.listenMediaKeyTaps()

        observers.append(NotificationCenter.default.addObserver(forName: .deviceListChanged,
                                                               object: nil,
                                                                queue: .main) { [weak self] _ in
            self?.statusBarController.createMenu()
        })

        observers.append(NotificationCenter.default.addObserver(forName: .defaultOutputDeviceChanged,
                                                               object: nil,
                                                                queue: .main) { [weak self] _ in
            self?.statusBarController.createMenu()
            self?.sendDeviceChangedNotification()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName: .deviceVolumeDidChange,
                                                               object: nil,
                                                                queue: .main) { [weak self] _ in
            if let volume = self?.audioManager.getSelectedDeviceVolume() {
                self?.statusBarController.updateVolume(value: volume * 100)
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - MediaManagerDelegate

extension ApplicationControllerImp: MediaManagerDelegate {
    func onMediaKeyTap(mediaKey: MediaKey) {
        guard let selectedDeviceVolume = audioManager.getSelectedDeviceVolume() else {
            return
        }
        
        let volumeStep: Float = 1 / Float(Constants.chicletsCount)
        var volume: Float = (selectedDeviceVolume / volumeStep).rounded() * volumeStep
        
        switch mediaKey {
        case .volumeUp:
            volume = (volume + volumeStep).clamped(to: 0...1)
            audioManager.setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)
            
        case .volumeDown:
            volume = (volume - volumeStep).clamped(to: 0...1)
            audioManager.setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)
            
        case .mute:
            audioManager.toggleMute()
            if audioManager.isSelectedDeviceMuted() {
                volume = 0
            } else {
                volume = audioManager.getSelectedDeviceVolume() ?? 0
            }
            
        default:
            break
        }
        
        let correctedVolume = volume * 100
        
        statusBarController.updateVolume(value: correctedVolume)
        mediaManager.showOSD(volume: correctedVolume, chicletsCount: Constants.chicletsCount)
        
        Logger.debug(Constants.InnerMessages.selectedDeviceVolume(volume: String(correctedVolume)))
    }
}

extension ApplicationControllerImp {
    func sendDeviceChangedNotification() {
        if #available(macOS 10.14, *) {
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.requestAuthorization(options: [.alert]) { _, error in
                if error != nil {
                    print("Failed to add a notification request: \(String(describing: error))")
                }
                
                let selectedDevice = self.simplyCA.defaultOutputDevice
                
                let content = UNMutableNotificationContent()
                content.title = "Ouput Device Changed"
                content.body = selectedDevice?.name ?? "N/A"
                let uuidString = UUID().uuidString
                
                let date = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
                
                let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    if error != nil {
                        print("Failed to add a notification request: \(String(describing: error))")
                    }
                }
            }
        }
    }
}
