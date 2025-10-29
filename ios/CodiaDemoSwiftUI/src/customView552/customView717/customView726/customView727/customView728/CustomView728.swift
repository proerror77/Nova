//
//  CustomView728.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView728: View {
    @State public var image508Path: String = "image508_42305"
    @State public var text346Text: String = "2"
    @State public var text347Text: String = "Lucy Liu"
    @State public var text348Text: String = "Morgan Stanley"
    @State public var text349Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image508Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView729(text346Text: text346Text)
                .frame(width: 35, height: 35)
            CustomView731(
                text347Text: text347Text,
                text348Text: text348Text)
                .frame(width: 99, height: 38)
            CustomView732(text349Text: text349Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView728_Previews: PreviewProvider {
    static var previews: some View {
        CustomView728()
    }
}
