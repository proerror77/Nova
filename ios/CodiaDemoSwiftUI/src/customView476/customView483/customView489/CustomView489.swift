//
//  CustomView489.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView489: View {
    @State public var image304Path: String = "image304_41549"
    @State public var text242Text: String = "Hello, how are you bro~"
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(image304Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50, alignment: .topLeading)
                .cornerRadius(25)
            CustomView490(text242Text: text242Text)
                .frame(width: 227, height: 46)
        }
        .frame(width: 283, height: 50, alignment: .top)
    }
}

struct CustomView489_Previews: PreviewProvider {
    static var previews: some View {
        CustomView489()
    }
}
