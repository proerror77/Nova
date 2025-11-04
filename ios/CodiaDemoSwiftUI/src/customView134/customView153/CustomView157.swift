//
//  CustomView157.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView157: View {
    @State public var text87Text: String = "Devices"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text87Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView157_Previews: PreviewProvider {
    static var previews: some View {
        CustomView157()
    }
}
