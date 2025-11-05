//
//  AGInputPickerButton.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGInputPickerButton: View {
    @Binding var outputType: AGOutputType
    @State private var animate = false
    
    public var body: some View {
        Picker("", selection: $outputType) {
            ForEach(AGOutputType.allCases) { type in
                Text(type.title.uppercased())
                    .foregroundStyle(type == outputType ? .yellow : .white)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}
