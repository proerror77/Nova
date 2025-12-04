//
//  CustomView550.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView550: View {
    @State public var text260Text: String = "Bruce Li"
    @State public var image380Path: String = "image380_41872"
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(text260Text)
                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 21))
                .lineLimit(1)
                .frame(width: 83, alignment: .leading)
                .multilineTextAlignment(.leading)
            Image(image380Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 5, alignment: .topLeading)
        }
        .frame(width: 100, height: 16, alignment: .top)
    }
}

struct CustomView550_Previews: PreviewProvider {
    static var previews: some View {
        CustomView550()
    }
}
