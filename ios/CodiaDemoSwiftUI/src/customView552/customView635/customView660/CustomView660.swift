//
//  CustomView660.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView660: View {
    @State public var image460Path: String = "image460_42143"
    @State public var text314Text: String = "4"
    @State public var text315Text: String = "Lucy Liu"
    @State public var text316Text: String = "Morgan Stanley"
    @State public var text317Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView661(
                image460Path: image460Path,
                text314Text: text314Text,
                text315Text: text315Text,
                text316Text: text316Text,
                text317Text: text317Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView660_Previews: PreviewProvider {
    static var previews: some View {
        CustomView660()
    }
}
