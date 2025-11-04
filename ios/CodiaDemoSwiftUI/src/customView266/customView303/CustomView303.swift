//
//  CustomView303.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView303: View {
    @State public var image210Path: String = "image210_4973"
    @State public var text170Text: String = "Liam"
    @State public var text171Text: String = "Hello, how are you bro~"
    @State public var text172Text: String = "09:41 PM"
    @State public var image211Path: String = "image211_4982"
    @State public var text173Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView305(
                image210Path: image210Path,
                text170Text: text170Text,
                text171Text: text171Text,
                text172Text: text172Text,
                image211Path: image211Path,
                text173Text: text173Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView303_Previews: PreviewProvider {
    static var previews: some View {
        CustomView303()
    }
}
