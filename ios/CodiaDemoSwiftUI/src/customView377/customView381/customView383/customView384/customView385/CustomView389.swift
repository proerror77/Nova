//
//  CustomView389.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView389: View {
    @State public var text207Text: String = "4"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text207Text)
                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView389_Previews: PreviewProvider {
    static var previews: some View {
        CustomView389()
    }
}
