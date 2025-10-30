//
//  CustomView301.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView301: View {
    @State public var text168Text: String = "09:41 PM"
    @State public var image209Path: String = "image209_I49694966"
    @State public var text169Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text168Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView302(
                image209Path: image209Path,
                text169Text: text169Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView301_Previews: PreviewProvider {
    static var previews: some View {
        CustomView301()
    }
}
