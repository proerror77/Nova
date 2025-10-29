//
//  CustomView329.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView329: View {
    @State public var text184Text: String = "09:41 PM"
    @State public var image217Path: String = "image217_41024"
    @State public var text185Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text184Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView330(
                image217Path: image217Path,
                text185Text: text185Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView329_Previews: PreviewProvider {
    static var previews: some View {
        CustomView329()
    }
}
