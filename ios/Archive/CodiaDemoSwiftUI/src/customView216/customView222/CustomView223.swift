//
//  CustomView223.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView223: View {
    @State public var image160Path: String = "image160_I479741093"
    @State public var text118Text: String = "Share invitation link "
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            Image(image160Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16, alignment: .topLeading)
            Text(text118Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView223_Previews: PreviewProvider {
    static var previews: some View {
        CustomView223()
    }
}
