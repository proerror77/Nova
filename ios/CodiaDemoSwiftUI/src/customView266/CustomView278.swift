//
//  CustomView278.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView278: View {
    @State public var image201Path: String = "image201_4943"
    @State public var text155Text: String = "Home"
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Image(image201Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 20, alignment: .topLeading)
            Text(text155Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 44, alignment: .topLeading)
    }
}

struct CustomView278_Previews: PreviewProvider {
    static var previews: some View {
        CustomView278()
    }
}
