//
//  AGOutputType.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import Foundation

public enum AGOutputType: CaseIterable, Identifiable, Sendable {
    case photo, video

    public var id: Self { self }

    public var title: String {
        switch self {
        case .photo:
            "Photo"
        case .video:
            "Video"
        }
    }
}
