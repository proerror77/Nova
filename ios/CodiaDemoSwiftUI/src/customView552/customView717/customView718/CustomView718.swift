//
//  CustomView718.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView718: View {
    @State public var image502Path: String = "image502_42285"
    @State public var text342Text: String = "1"
    @State public var text343Text: String = "Lucy Liu"
    @State public var text344Text: String = "Morgan Stanley"
    @State public var text345Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView719(
                image502Path: image502Path,
                text342Text: text342Text,
                text343Text: text343Text,
                text344Text: text344Text,
                text345Text: text345Text)
                .frame(width: 309, height: 389)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView718_Previews: PreviewProvider {
    static var previews: some View {
        CustomView718()
    }
}
