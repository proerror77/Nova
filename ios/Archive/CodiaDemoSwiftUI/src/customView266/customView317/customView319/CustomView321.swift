//
//  CustomView321.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView321: View {
    @State public var text178Text: String = "Liam"
    @State public var text179Text: String = "Hello, how are you bro~"
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text178Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 19))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text179Text)
                .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 161, height: 46, alignment: .topLeading)
    }
}

struct CustomView321_Previews: PreviewProvider {
    static var previews: some View {
        CustomView321()
    }
}
