//
//  CustomView314.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView314: View {
    @State public var text174Text: String = "Liam"
    @State public var text175Text: String = "Hello, how are you bro~"
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text174Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 19))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text175Text)
                .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 161, height: 46, alignment: .topLeading)
    }
}

struct CustomView314_Previews: PreviewProvider {
    static var previews: some View {
        CustomView314()
    }
}
