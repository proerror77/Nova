//
//  CustomView315.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView315: View {
    @State public var text176Text: String = "09:41 PM"
    @State public var image213Path: String = "image213_4996"
    @State public var text177Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text176Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView316(
                image213Path: image213Path,
                text177Text: text177Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView315_Previews: PreviewProvider {
    static var previews: some View {
        CustomView315()
    }
}
