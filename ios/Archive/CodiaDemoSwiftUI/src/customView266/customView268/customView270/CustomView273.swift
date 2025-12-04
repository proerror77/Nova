//
//  CustomView273.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView273: View {
    @State public var text151Text: String = "09:41 PM"
    @State public var image195Path: String = "image195_4930"
    @State public var text152Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text151Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView274(
                image195Path: image195Path,
                text152Text: text152Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView273_Previews: PreviewProvider {
    static var previews: some View {
        CustomView273()
    }
}
