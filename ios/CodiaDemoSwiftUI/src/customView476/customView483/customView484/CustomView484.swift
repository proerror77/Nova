//
//  CustomView484.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView484: View {
    @State public var text240Text: String = "Uh-huh..."
    @State public var image303Path: String = "image303_41544"
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            CustomView485(text240Text: text240Text)
                .frame(width: 111, height: 46)
            Image(image303Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50, alignment: .topLeading)
                .cornerRadius(25)
        }
        .frame(width: 167, height: 50, alignment: .top)
    }
}

struct CustomView484_Previews: PreviewProvider {
    static var previews: some View {
        CustomView484()
    }
}
