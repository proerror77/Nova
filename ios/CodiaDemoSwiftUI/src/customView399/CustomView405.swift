//
//  CustomView405.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView405: View {
    @State public var image258Path: String = "image258_41321"
    @State public var text216Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image258Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.005, height: 18.002, alignment: .topLeading)
            Text(text216Text)
                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView405_Previews: PreviewProvider {
    static var previews: some View {
        CustomView405()
    }
}
