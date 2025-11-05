//
//  AGPermissionsResult.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import Foundation

public struct AGPermissionsResult {
    public let camera: Bool
    public let microphone: Bool
    public let photoLibrary: Bool

    public var allGranted: Bool {
        camera && microphone && photoLibrary
    }

    public var deniedPermissions: [String] {
        var denied: [String] = []
        if !camera { denied.append("Camera") }
        if !microphone { denied.append("Microphone") }
        if !photoLibrary { denied.append("Photo Library") }
        return denied
    }
}
