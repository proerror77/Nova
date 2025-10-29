//
//  CustomView128.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView128: View {
    @State public var text80Text: String = "OK"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text80Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 22))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(EdgeInsets(top: 8, leading: 42, bottom: 8, trailing: 42))
        .frame(width: 116, height: 37, alignment: .top)
        .background(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 18.5))
    }
}

struct CustomView128_Previews: PreviewProvider {
    static var previews: some View {
        CustomView128()
    }
}
