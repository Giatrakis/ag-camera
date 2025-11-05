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
        if #available(iOS 26.0, *) {
            Picker("", selection: $outputType) { typesView }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.large)
                .glassEffect()
        } else {
            Picker("", selection: $outputType) { typesView }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.large)
                .glassEffect()
        }
        
    }
    
    private var typesView: some View {
        ForEach(AGOutputType.allCases) { type in
            Text(type.title.uppercased())
                .foregroundStyle(type == outputType ? .yellow : .white)
        }
    }
}
