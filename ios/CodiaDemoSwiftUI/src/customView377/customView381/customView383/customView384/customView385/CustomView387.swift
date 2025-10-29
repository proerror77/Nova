//
//  CustomView387.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView387: View {
    @State public var text206Text: String = "All contacts"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text206Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView387_Previews: PreviewProvider {
    static var previews: some View {
        CustomView387()
    }
}
