//
//  CustomView505.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView505: View {
    @State public var image312Path: String = "image312_41606"
    @State public var text247Text: String = "Hello, how are you bro~"
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(image312Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50, alignment: .topLeading)
                .cornerRadius(25)
            CustomView506(text247Text: text247Text)
                .frame(width: 227, height: 46)
        }
        .frame(width: 283, height: 50, alignment: .top)
    }
}

struct CustomView505_Previews: PreviewProvider {
    static var previews: some View {
        CustomView505()
    }
}
