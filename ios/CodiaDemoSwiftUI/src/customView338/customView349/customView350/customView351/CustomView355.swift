//
//  CustomView355.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView355: View {
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text195Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 16))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text196Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 11.5))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 105, alignment: .leading)
    }
}

struct CustomView355_Previews: PreviewProvider {
    static var previews: some View {
        CustomView355()
    }
}
