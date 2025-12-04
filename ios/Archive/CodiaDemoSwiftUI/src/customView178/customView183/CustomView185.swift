//
//  CustomView185.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView185: View {
    @State public var text96Text: String = "Account_one"
    @State public var text97Text: String = "Icered"
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text96Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 19))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text97Text)
                .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 161, height: 46, alignment: .topLeading)
    }
}

struct CustomView185_Previews: PreviewProvider {
    static var previews: some View {
        CustomView185()
    }
}
