//
//  CustomView717.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView717: View {
    @State public var image502Path: String = "image502_42285"
    @State public var text342Text: String = "1"
    @State public var text343Text: String = "Lucy Liu"
    @State public var text344Text: String = "Morgan Stanley"
    @State public var text345Text: String = "2293"
    @State public var image508Path: String = "image508_42305"
    @State public var text346Text: String = "2"
    @State public var text347Text: String = "Lucy Liu"
    @State public var text348Text: String = "Morgan Stanley"
    @State public var text349Text: String = "2293"
    @State public var image514Path: String = "image514_42325"
    @State public var text350Text: String = "3"
    @State public var text351Text: String = "Lucy Liu"
    @State public var text352Text: String = "Morgan Stanley"
    @State public var text353Text: String = "2293"
    @State public var image520Path: String = "image520_42345"
    @State public var text354Text: String = "4"
    @State public var text355Text: String = "Lucy Liu"
    @State public var text356Text: String = "Morgan Stanley"
    @State public var text357Text: String = "2293"
    @State public var image526Path: String = "image526_42365"
    @State public var text358Text: String = "5"
    @State public var text359Text: String = "Lucy Liu"
    @State public var text360Text: String = "Morgan Stanley"
    @State public var text361Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView718(
                image502Path: image502Path,
                text342Text: text342Text,
                text343Text: text343Text,
                text344Text: text344Text,
                text345Text: text345Text)
                .frame(width: 309, height: 389)
                .offset(x: -1252)
            CustomView726(
                image508Path: image508Path,
                text346Text: text346Text,
                text347Text: text347Text,
                text348Text: text348Text,
                text349Text: text349Text)
                .frame(width: 311, height: 392)
                .offset(x: -933)
            CustomView734(
                image514Path: image514Path,
                text350Text: text350Text,
                text351Text: text351Text,
                text352Text: text352Text,
                text353Text: text353Text)
                .frame(width: 312, height: 392)
                .offset(x: -612)
            CustomView742(
                image520Path: image520Path,
                text354Text: text354Text,
                text355Text: text355Text,
                text356Text: text356Text,
                text357Text: text357Text)
                .frame(width: 311, height: 392)
                .offset(x: -290)
            CustomView750(
                image526Path: image526Path,
                text358Text: text358Text,
                text359Text: text359Text,
                text360Text: text360Text,
                text361Text: text361Text)
                .frame(width: 311, height: 392)
                .offset(x: 41)
        }
        .frame(width: 393, height: 392, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView717_Previews: PreviewProvider {
    static var previews: some View {
        CustomView717()
    }
}
