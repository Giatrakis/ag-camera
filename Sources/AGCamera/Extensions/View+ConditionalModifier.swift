//
//  View+ConditionalModifier.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 18/12/25.
//

import SwiftUI

public extension View {
    @ViewBuilder
    func conditionalModifier<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
