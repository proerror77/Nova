//
//  CustomView485.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView485: View {
    @State public var text240Text: String = "Uh-huh..."
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 0.40))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .frame(width: 111, height: 46)
                HStack {
                    Spacer()
                        Text(text240Text)
                            .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 13)
        }
        .frame(width: 111, height: 46, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

struct CustomView485_Previews: PreviewProvider {
    static var previews: some View {
        CustomView485()
    }
}
