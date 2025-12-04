//
//  CustomView76.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView76: View {
    @State public var image69Path: String = "image69_4409"
    @State public var text44Text: String = "Home"
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Image(image69Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 20, alignment: .topLeading)
            Text(text44Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 44, alignment: .topLeading)
    }
}

struct CustomView76_Previews: PreviewProvider {
    static var previews: some View {
        CustomView76()
    }
}
