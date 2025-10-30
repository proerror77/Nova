//
//  CustomView306.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView306: View {
    @State public var text170Text: String = "Liam"
    @State public var text171Text: String = "Hello, how are you bro~"
    @State public var text172Text: String = "09:41 PM"
    @State public var image211Path: String = "image211_4982"
    @State public var text173Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView307(
                text170Text: text170Text,
                text171Text: text171Text)
                .frame(width: 161, height: 46)
            CustomView308(
                text172Text: text172Text,
                image211Path: image211Path,
                text173Text: text173Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView306_Previews: PreviewProvider {
    static var previews: some View {
        CustomView306()
    }
}
