//
//  CustomView553.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView553: View {
    @State public var image382Path: String = "image382_41881"
    @State public var text262Text: String = "1"
    @State public var text263Text: String = "Lucy Liu"
    @State public var text264Text: String = "Morgan Stanley"
    @State public var text265Text: String = "2293"
    @State public var image388Path: String = "image388_41901"
    @State public var text266Text: String = "2"
    @State public var text267Text: String = "Lucy Liu"
    @State public var text268Text: String = "Morgan Stanley"
    @State public var text269Text: String = "2293"
    @State public var image394Path: String = "image394_41921"
    @State public var text270Text: String = "3"
    @State public var text271Text: String = "Lucy Liu"
    @State public var text272Text: String = "Morgan Stanley"
    @State public var text273Text: String = "2293"
    @State public var image400Path: String = "image400_41941"
    @State public var text274Text: String = "4"
    @State public var text275Text: String = "Lucy Liu"
    @State public var text276Text: String = "Morgan Stanley"
    @State public var text277Text: String = "2293"
    @State public var image406Path: String = "image406_41961"
    @State public var text278Text: String = "5"
    @State public var text279Text: String = "Lucy Liu"
    @State public var text280Text: String = "Morgan Stanley"
    @State public var text281Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView554(
                image382Path: image382Path,
                text262Text: text262Text,
                text263Text: text263Text,
                text264Text: text264Text,
                text265Text: text265Text)
                .frame(width: 309, height: 389)
                .offset(x: 41)
            CustomView562(
                image388Path: image388Path,
                text266Text: text266Text,
                text267Text: text267Text,
                text268Text: text268Text,
                text269Text: text269Text)
                .frame(width: 311, height: 392)
                .offset(x: 370)
            CustomView570(
                image394Path: image394Path,
                text270Text: text270Text,
                text271Text: text271Text,
                text272Text: text272Text,
                text273Text: text273Text)
                .frame(width: 312, height: 392)
                .offset(x: 701)
            CustomView578(
                image400Path: image400Path,
                text274Text: text274Text,
                text275Text: text275Text,
                text276Text: text276Text,
                text277Text: text277Text)
                .frame(width: 311, height: 392)
                .offset(x: 1023)
            CustomView586(
                image406Path: image406Path,
                text278Text: text278Text,
                text279Text: text279Text,
                text280Text: text280Text,
                text281Text: text281Text)
                .frame(width: 311, height: 392)
                .offset(x: 1344)
        }
        .frame(width: 392, height: 392, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView553_Previews: PreviewProvider {
    static var previews: some View {
        CustomView553()
    }
}
