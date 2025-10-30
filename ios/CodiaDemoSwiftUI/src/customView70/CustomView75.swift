//
//  CustomView75.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView75: View {
    @State public var image67Path: String = "image67_I44044382"
    @State public var text42Text: String = "Message"
    var body: some View {
        VStack(alignment: .center, spacing: -2) {
            Image(image67Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22, alignment: .topLeading)
            Text(text42Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 42, alignment: .topLeading)
    }
}

struct CustomView75_Previews: PreviewProvider {
    static var previews: some View {
        CustomView75()
    }
}
