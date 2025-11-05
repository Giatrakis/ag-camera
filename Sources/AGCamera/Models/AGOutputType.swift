//
//  AGOutputType.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import Foundation

enum AGOutputType: CaseIterable, Identifiable {
    case photo, video
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .photo:
            "Photo"
        case .video:
            "Video"
        }
    }
}
