//
//  CustomView81.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView81: View {
    @State public var image73Path: String = "image73_4423"
    @State public var text49Text: String = "Bruce Li"
    @State public var text50Text: String = "China"
    var body: some View {
        VStack(alignment: .center, spacing: 13) {
            Image(image73Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 137, height: 136, alignment: .topLeading)
            Text(text49Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 21))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text50Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 14))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 137, alignment: .leading)
    }
}

struct CustomView81_Previews: PreviewProvider {
    static var previews: some View {
        CustomView81()
    }
}
