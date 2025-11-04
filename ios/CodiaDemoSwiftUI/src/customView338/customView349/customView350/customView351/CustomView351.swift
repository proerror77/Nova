//
//  CustomView351.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView351: View {
    @State public var text194Text: String = "Icered contacts above"
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    @State public var image231Path: String = "image231_41110"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text194Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 17.5))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 9.5)
            CustomView352(
                image230Path: image230Path,
                text195Text: text195Text,
                text196Text: text196Text,
                image231Path: image231Path)
                .frame(width: 337.08, height: 67)
                .offset(y: 30)
        }
        .frame(width: 319, height: 97, alignment: .topLeading)
    }
}

struct CustomView351_Previews: PreviewProvider {
    static var previews: some View {
        CustomView351()
    }
}
