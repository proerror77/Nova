//
//  CustomView726.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView726: View {
    @State public var image508Path: String = "image508_42305"
    @State public var text346Text: String = "2"
    @State public var text347Text: String = "Lucy Liu"
    @State public var text348Text: String = "Morgan Stanley"
    @State public var text349Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView727(
                image508Path: image508Path,
                text346Text: text346Text,
                text347Text: text347Text,
                text348Text: text348Text,
                text349Text: text349Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView726_Previews: PreviewProvider {
    static var previews: some View {
        CustomView726()
    }
}
