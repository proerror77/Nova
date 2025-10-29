//
//  CustomView276.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView276: View {
    @State public var image199Path: String = "image199_4937"
    @State public var text153Text: String = "Message"
    var body: some View {
        VStack(alignment: .center, spacing: -2) {
            Image(image199Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22, alignment: .topLeading)
            Text(text153Text)
                .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 42, alignment: .topLeading)
    }
}

struct CustomView276_Previews: PreviewProvider {
    static var previews: some View {
        CustomView276()
    }
}
