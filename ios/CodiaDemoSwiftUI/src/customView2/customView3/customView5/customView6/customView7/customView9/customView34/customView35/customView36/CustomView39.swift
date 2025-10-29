//
//  CustomView39.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView39: View {
    @State public var text16Text: String = "Lucy Liu"
    @State public var text17Text: String = "Morgan Stanley"
    var body: some View {
        VStack(alignment: .leading) {
            Text(text16Text)
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 18))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text17Text)
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .frame(width: 119, height: 38, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 99, height: 38, alignment: .topLeading)
    }
}

struct CustomView39_Previews: PreviewProvider {
    static var previews: some View {
        CustomView39()
    }
}
