//
//  CustomView548.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView548: View {
    @State public var image378Path: String = "image378_41863"
    @State public var text259Text: String = "Add an alias account (Anonymous)"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image378Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42, alignment: .topLeading)
                .cornerRadius(21)
            Text(text259Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 14))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView548_Previews: PreviewProvider {
    static var previews: some View {
        CustomView548()
    }
}
