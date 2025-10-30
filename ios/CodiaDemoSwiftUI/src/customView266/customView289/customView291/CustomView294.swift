//
//  CustomView294.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView294: View {
    @State public var text164Text: String = "09:41 PM"
    @State public var image207Path: String = "image207_I49684966"
    @State public var text165Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text164Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView295(
                image207Path: image207Path,
                text165Text: text165Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView294_Previews: PreviewProvider {
    static var previews: some View {
        CustomView294()
    }
}
