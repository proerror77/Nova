//
//  CustomView466.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView466: View {
    @State public var text233Text: String = "All"
    @State public var image289Path: String = "image289_41444"
    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Text(text233Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 22))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Image(image289Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 8, alignment: .topLeading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView466_Previews: PreviewProvider {
    static var previews: some View {
        CustomView466()
    }
}
