//
//  CustomView719.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView719: View {
    @State public var image502Path: String = "image502_42285"
    @State public var text342Text: String = "1"
    @State public var text343Text: String = "Lucy Liu"
    @State public var text344Text: String = "Morgan Stanley"
    @State public var text345Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView720(
                image502Path: image502Path,
                text342Text: text342Text,
                text343Text: text343Text,
                text344Text: text344Text,
                text345Text: text345Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView719_Previews: PreviewProvider {
    static var previews: some View {
        CustomView719()
    }
}
