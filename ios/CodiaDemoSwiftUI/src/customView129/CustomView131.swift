//
//  CustomView131.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView131: View {
    @State public var text81Text: String = "Bruce Li"
    @State public var image100Path: String = "image100_I456341875"
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(text81Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 21))
                .lineLimit(1)
                .frame(width: 83, alignment: .leading)
                .multilineTextAlignment(.leading)
            Image(image100Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 5, alignment: .topLeading)
        }
        .frame(width: 100, height: 16, alignment: .top)
    }
}

struct CustomView131_Previews: PreviewProvider {
    static var previews: some View {
        CustomView131()
    }
}
