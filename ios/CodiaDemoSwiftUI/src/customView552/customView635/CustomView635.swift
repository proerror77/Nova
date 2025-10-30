//
//  CustomView635.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView635: View {
    @State public var image442Path: String = "image442_42083"
    @State public var text302Text: String = "1"
    @State public var text303Text: String = "Lucy Liu"
    @State public var text304Text: String = "Morgan Stanley"
    @State public var text305Text: String = "2293"
    @State public var image448Path: String = "image448_42103"
    @State public var text306Text: String = "2"
    @State public var text307Text: String = "Lucy Liu"
    @State public var text308Text: String = "Morgan Stanley"
    @State public var text309Text: String = "2293"
    @State public var image454Path: String = "image454_42123"
    @State public var text310Text: String = "3"
    @State public var text311Text: String = "Lucy Liu"
    @State public var text312Text: String = "Morgan Stanley"
    @State public var text313Text: String = "2293"
    @State public var image460Path: String = "image460_42143"
    @State public var text314Text: String = "4"
    @State public var text315Text: String = "Lucy Liu"
    @State public var text316Text: String = "Morgan Stanley"
    @State public var text317Text: String = "2293"
    @State public var image466Path: String = "image466_42163"
    @State public var text318Text: String = "5"
    @State public var text319Text: String = "Lucy Liu"
    @State public var text320Text: String = "Morgan Stanley"
    @State public var text321Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView636(
                image442Path: image442Path,
                text302Text: text302Text,
                text303Text: text303Text,
                text304Text: text304Text,
                text305Text: text305Text)
                .frame(width: 309, height: 389)
                .offset(x: -609)
            CustomView644(
                image448Path: image448Path,
                text306Text: text306Text,
                text307Text: text307Text,
                text308Text: text308Text,
                text309Text: text309Text)
                .frame(width: 311, height: 392)
                .offset(x: -290)
            CustomView652(
                image454Path: image454Path,
                text310Text: text310Text,
                text311Text: text311Text,
                text312Text: text312Text,
                text313Text: text313Text)
                .frame(width: 312, height: 392)
                .offset(x: 41)
            CustomView660(
                image460Path: image460Path,
                text314Text: text314Text,
                text315Text: text315Text,
                text316Text: text316Text,
                text317Text: text317Text)
                .frame(width: 311, height: 392)
                .offset(x: 373)
            CustomView668(
                image466Path: image466Path,
                text318Text: text318Text,
                text319Text: text319Text,
                text320Text: text320Text,
                text321Text: text321Text)
                .frame(width: 311, height: 392)
                .offset(x: 694)
        }
        .frame(width: 393, height: 392, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView635_Previews: PreviewProvider {
    static var previews: some View {
        CustomView635()
    }
}
