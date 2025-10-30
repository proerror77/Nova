//
//  CustomView67.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView67: View {
    @State public var image59Path: String = "image59_4385"
    @State public var text40Text: String = "Account"
    var body: some View {
        VStack(alignment: .center, spacing: -4) {
            Image(image59Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24, alignment: .topLeading)
            Text(text40Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 42, alignment: .topLeading)
    }
}

struct CustomView67_Previews: PreviewProvider {
    static var previews: some View {
        CustomView67()
    }
}
