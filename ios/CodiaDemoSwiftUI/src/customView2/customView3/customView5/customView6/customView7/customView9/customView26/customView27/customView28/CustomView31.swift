//
//  CustomView31.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView31: View {
    @State public var text12Text: String = "Lucy Liu"
    @State public var text13Text: String = "Morgan Stanley"
    var body: some View {
        VStack(alignment: .leading) {
            Text(text12Text)
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 18))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text13Text)
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .frame(width: 119, height: 38, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 99, height: 38, alignment: .topLeading)
    }
}

struct CustomView31_Previews: PreviewProvider {
    static var previews: some View {
        CustomView31()
    }
}
