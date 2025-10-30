//
//  CustomView661.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView661: View {
    @State public var image460Path: String = "image460_42143"
    @State public var text314Text: String = "4"
    @State public var text315Text: String = "Lucy Liu"
    @State public var text316Text: String = "Morgan Stanley"
    @State public var text317Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView662(
                image460Path: image460Path,
                text314Text: text314Text,
                text315Text: text315Text,
                text316Text: text316Text,
                text317Text: text317Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView661_Previews: PreviewProvider {
    static var previews: some View {
        CustomView661()
    }
}
