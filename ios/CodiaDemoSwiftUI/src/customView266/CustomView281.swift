//
//  CustomView281.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView281: View {
    @State public var image203Path: String = "image203_4952"
    @State public var text157Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image203Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.005, height: 18.002, alignment: .topLeading)
            Text(text157Text)
                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 349, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}

struct CustomView281_Previews: PreviewProvider {
    static var previews: some View {
        CustomView281()
    }
}
