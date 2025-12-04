//
//  CustomView336.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView336: View {
    @State public var text188Text: String = "09:41 PM"
    @State public var image219Path: String = "image219_41038"
    @State public var text189Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text188Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView337(
                image219Path: image219Path,
                text189Text: text189Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView336_Previews: PreviewProvider {
    static var previews: some View {
        CustomView336()
    }
}
