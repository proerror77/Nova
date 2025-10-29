//
//  CustomView498.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView498: View {
    @State public var image308Path: String = "image308_41570"
    @State public var text244Text: String = "Eli"
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(image308Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50, alignment: .topLeading)
                .cornerRadius(25)
            Text(text244Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 86, height: 50, alignment: .topTrailing)
    }
}

struct CustomView498_Previews: PreviewProvider {
    static var previews: some View {
        CustomView498()
    }
}
