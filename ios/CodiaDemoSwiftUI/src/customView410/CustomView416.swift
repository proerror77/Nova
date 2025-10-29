//
//  CustomView416.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView416: View {
    @State public var image265Path: String = "image265_41346"
    @State public var text219Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image265Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.005, height: 18.002, alignment: .topLeading)
            Text(text219Text)
                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView416_Previews: PreviewProvider {
    static var previews: some View {
        CustomView416()
    }
}
