//
//  CustomView220.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView220: View {
    @State public var image159Path: String = "image159_I47954952"
    @State public var text117Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image159Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.005, height: 18.002, alignment: .topLeading)
            Text(text117Text)
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

struct CustomView220_Previews: PreviewProvider {
    static var previews: some View {
        CustomView220()
    }
}
