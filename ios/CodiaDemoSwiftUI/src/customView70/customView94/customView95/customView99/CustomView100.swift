//
//  CustomView100.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView100: View {
    @State public var text64Text: String = "kyleegigstead Cyborg dreams"
    @State public var text65Text: String = "kyleegigstead Cyborg dreams"
    var body: some View {
        VStack(alignment: .leading) {
            Text(text64Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 8))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text65Text)
                .foregroundColor(Color(red: 0.45, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 5.5))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 111, alignment: .leading)
    }
}

struct CustomView100_Previews: PreviewProvider {
    static var previews: some View {
        CustomView100()
    }
}
