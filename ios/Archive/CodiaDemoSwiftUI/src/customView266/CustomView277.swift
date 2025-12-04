//
//  CustomView277.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView277: View {
    @State public var image200Path: String = "image200_4940"
    @State public var text154Text: String = "Account"
    var body: some View {
        VStack(alignment: .center, spacing: -4) {
            Image(image200Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24, alignment: .topLeading)
            Text(text154Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 42, alignment: .topLeading)
    }
}

struct CustomView277_Previews: PreviewProvider {
    static var previews: some View {
        CustomView277()
    }
}
